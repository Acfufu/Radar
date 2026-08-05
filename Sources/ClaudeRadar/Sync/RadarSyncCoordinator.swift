import Foundation

struct RadarSyncProjection: Sendable {
    let supportLevel: SupportLevel
    let benchmark: SegmentState<BenchmarkDataset>
    let community: SegmentState<CommunityDataset>
    let sourceStatus: SegmentState<SourceStatusDataset>
}

struct SyncLifecycleState: Sendable {
    let isStopped: Bool
    let isPaused: Bool
    let hasActiveTask: Bool
}

struct SyncEndpointEligibility: Sendable {
    let shared: Bool
    let community: Bool

    var hasEligibleEndpoint: Bool { shared || community }

    func intersecting(_ other: SyncEndpointEligibility) -> SyncEndpointEligibility {
        SyncEndpointEligibility(shared: shared && other.shared, community: community && other.community)
    }

    func excluding(_ other: SyncEndpointEligibility) -> SyncEndpointEligibility {
        SyncEndpointEligibility(shared: shared && !other.shared, community: community && !other.community)
    }
}

actor RadarSyncCoordinator {
    let source: RadarHTTPSource
    let repository: RadarRepository
    var sourceID: RadarSourceID { source.descriptor.id }
    var policy: SyncPolicy
    let clock: any RadarClock
    private let networkMonitor: (any NetworkMonitoring)?
    private let sleepNotifier: (any SleepRecoveryNotifying)?
    let projectionDidChange: (@Sendable (RadarSyncProjection) async -> Void)?
    let persistenceCheckpoint: (@Sendable () async -> Void)?
    private let triggerObserver: (@Sendable (SyncTrigger) -> Void)?
    private var activeTask: Task<Void, Never>?
    private var activeTrigger: SyncTrigger?
    private var activeRefreshID = 0
    private var lastManualRefreshID: Int?
    private var lastPerformedRefreshID: Int?
    private var lastPerformedEligibility = SyncEndpointEligibility(shared: false, community: false)
    private var periodicTask: Task<Void, Never>?
    private var periodicRefreshStarted = false
    var isStopped = false
    var isPaused = false
    var failureCount = 0
    var backoffDeadline: Date?
    var lifecycleGeneration = 0
    private var lifecycleTriggersStarted = false
    var persistenceTasks: [Int: Task<Void, Never>] = [:]
    var nextPersistenceID = 0
    private var pauseOperation: Task<Void, Never>?
    private var stopOperation: Task<Void, Never>?

    init(
        source: RadarHTTPSource,
        repository: RadarRepository,
        policy: SyncPolicy = SyncPolicy(),
        clock: any RadarClock = SystemRadarClock(),
        networkMonitor: (any NetworkMonitoring)? = nil,
        sleepNotifier: (any SleepRecoveryNotifying)? = nil,
        projectionDidChange: (@Sendable (RadarSyncProjection) async -> Void)? = nil,
        persistenceCheckpoint: (@Sendable () async -> Void)? = nil,
        triggerObserver: (@Sendable (SyncTrigger) -> Void)? = nil
    ) {
        self.source = source
        self.repository = repository
        self.policy = policy
        self.clock = clock
        self.networkMonitor = networkMonitor
        self.sleepNotifier = sleepNotifier
        self.projectionDidChange = projectionDidChange
        self.persistenceCheckpoint = persistenceCheckpoint
        self.triggerObserver = triggerObserver
    }

    func refresh(trigger: SyncTrigger) async {
        guard !isStopped, !isPaused else { return }
        triggerObserver?(trigger)
        await refresh(trigger: trigger, eligibilityLimit: nil)
    }

    private func refresh(trigger: SyncTrigger, eligibilityLimit: SyncEndpointEligibility?) async {
        guard !isStopped, !isPaused else { return }
        if let activeTask {
            let joinedID = activeRefreshID
            activeTrigger = strongest(activeTrigger ?? trigger, trigger)
            await activeTask.value
            if self.activeRefreshID == joinedID { self.activeTask = nil }
            if trigger.isManual, !isStopped, !isPaused, lastManualRefreshID != joinedID {
                let performed = lastPerformedRefreshID == joinedID
                    ? lastPerformedEligibility
                    : SyncEndpointEligibility(shared: false, community: false)
                let eligible = await eligibleEndpoints(for: trigger).excluding(performed)
                if eligible.hasEligibleEndpoint {
                    await refresh(trigger: trigger, eligibilityLimit: eligible)
                }
            }
            return
        }
        let generation = lifecycleGeneration
        activeRefreshID += 1
        let refreshID = activeRefreshID
        activeTrigger = trigger
        let task = Task {
            await Task.yield()
            guard self.lifecycleAllowsWork(generation) else { return }
            let selectedTrigger = self.selectedTrigger(fallback: trigger)
            var eligibility = await self.eligibleEndpoints(for: selectedTrigger)
            guard self.lifecycleAllowsWork(generation) else { return }
            if let eligibilityLimit {
                eligibility = eligibility.intersecting(eligibilityLimit)
            }
            guard eligibility.hasEligibleEndpoint else { return }
            self.markPerformed(refreshID, trigger: selectedTrigger, eligibility: eligibility)
            await self.performSync(generation: generation, eligibility: eligibility)
        }
        activeTask = task
        await task.value
        if !isStopped, activeRefreshID == refreshID {
            activeTask = nil
            activeTrigger = nil
        }
    }

    func startPeriodicRefresh() {
        guard !isStopped else { return }
        periodicRefreshStarted = true
        schedulePeriodicRefresh()
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        policy = SyncPolicy(
            refreshInterval: interval,
            recoveryMinimumInterval: policy.recoveryMinimumInterval,
            maximumBackoff: policy.maximumBackoff
        )
        guard periodicRefreshStarted, !isStopped else { return }
        periodicTask?.cancel()
        periodicTask = nil
        schedulePeriodicRefresh()
    }

    private func schedulePeriodicRefresh() {
        guard periodicTask == nil else { return }
        let interval = policy.refreshInterval
        periodicTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                await self.refresh(trigger: .periodic)
            }
        }
    }

    func startLifecycleTriggers() {
        guard !isStopped, !lifecycleTriggersStarted else { return }
        lifecycleTriggersStarted = true
        networkMonitor?.start { [weak self] in
            guard let self else { return }
            Task { await self.refresh(trigger: .networkRecovery) }
        }
        sleepNotifier?.start { [weak self] in
            guard let self else { return }
            Task { await self.refresh(trigger: .sleepRecovery) }
        }
    }

    func stop() async {
        if let stopOperation {
            await stopOperation.value
            return
        }
        guard !isStopped else { return }
        isStopped = true
        lifecycleGeneration += 1
        periodicTask?.cancel()
        periodicTask = nil
        periodicRefreshStarted = false
        let task = activeTask
        activeTask = nil
        activeTrigger = nil
        task?.cancel()
        networkMonitor?.stop()
        sleepNotifier?.stop()
        let pausing = pauseOperation
        let registeredPersistence = Array(persistenceTasks.values)
        let operation = Task { [source] in
            if let pausing {
                await pausing.value
            } else {
                await source.cancelAll()
            }
            for task in registeredPersistence { await task.value }
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
        let refresh = activeTask
        activeTask = nil
        activeTrigger = nil
        refresh?.cancel()
        let registeredPersistence = Array(persistenceTasks.values)
        let operation = Task { [source] in
            await source.cancelAll()
            if let refresh { await refresh.value }
            for task in registeredPersistence { await task.value }
        }
        pauseOperation = operation
        await operation.value
        pauseOperation = nil
    }

    func resume() {
        guard !isStopped, pauseOperation == nil else { return }
        isPaused = false
    }

    func lifecycleAllowsWork(_ generation: Int) -> Bool {
        !isStopped && !isPaused && generation == lifecycleGeneration
    }

    func lifecycleState() -> SyncLifecycleState {
        SyncLifecycleState(
            isStopped: isStopped,
            isPaused: isPaused,
            hasActiveTask: activeTask != nil
                || periodicTask != nil
                || pauseOperation != nil
                || !persistenceTasks.isEmpty
        )
    }

    func projection() async throws -> RadarSyncProjection {
        let now = clock.now()
        let benchmark = try await repository.benchmarkState(sourceID: sourceID)
        let community = try await repository.communityState(sourceID: sourceID)
        let status = try await repository.sourceStatusState(sourceID: sourceID)
        return RadarSyncProjection(
            supportLevel: source.descriptor.supportLevel,
            benchmark: stale(benchmark, now: now),
            community: stale(community, now: now),
            sourceStatus: stale(status, now: now)
        )
    }

    private func eligibleEndpoints(for trigger: SyncTrigger) async -> SyncEndpointEligibility {
        let now = clock.now()
        let benchmark = try? await repository.metadata(sourceID: sourceID, datasetType: .benchmark)
        let status = source.supportsSourceStatusSegment
            ? try? await repository.metadata(sourceID: sourceID, datasetType: .sourceStatus)
            : nil
        let community = try? await repository.metadata(sourceID: sourceID, datasetType: .community)
        var sharedEligible = endpointPermitted(metadata: [benchmark, status].compactMap { $0 }, trigger: trigger, now: now)
        var communityEligible = await source.hasCommunityEndpoint()
            && endpointPermitted(metadata: [community].compactMap { $0 }, trigger: trigger, now: now)
        if trigger == .networkRecovery || trigger == .sleepRecovery {
            if let state = try? await projection() {
                let benchmarkNeedsRecovery = state.benchmark.isStale || state.benchmark.error != nil
                let statusNeedsRecovery = state.sourceStatus.isStale || state.sourceStatus.error != nil
                sharedEligible = sharedEligible && (
                    benchmarkNeedsRecovery
                        || (source.supportsSourceStatusSegment && statusNeedsRecovery)
                )
                communityEligible = communityEligible && (state.community.isStale || state.community.error != nil)
            }
        }
        return SyncEndpointEligibility(shared: sharedEligible, community: communityEligible)
    }

    private func endpointPermitted(metadata: [SyncMetadata], trigger: SyncTrigger, now: Date) -> Bool {
        if metadata.compactMap(\.retryAfter).contains(where: { now < $0 }) { return false }
        if trigger != .manual,
           let deadline = metadata.compactMap(\.backoffUntil).max(),
           now < deadline {
            return false
        }
        if trigger == .networkRecovery || trigger == .sleepRecovery,
           let attempted = metadata.compactMap(\.lastAttemptedAt).max(),
           now.timeIntervalSince(attempted) < policy.recoveryMinimumInterval {
            return false
        }
        return true
    }

    private func selectedTrigger(fallback: SyncTrigger) -> SyncTrigger {
        activeTrigger ?? fallback
    }

    private func markPerformed(
        _ refreshID: Int,
        trigger: SyncTrigger,
        eligibility: SyncEndpointEligibility
    ) {
        lastPerformedRefreshID = refreshID
        lastPerformedEligibility = eligibility
        if trigger.isManual { lastManualRefreshID = refreshID }
    }

    private func strongest(_ lhs: SyncTrigger, _ rhs: SyncTrigger) -> SyncTrigger {
        lhs.priority >= rhs.priority ? lhs : rhs
    }

    private func stale<Value>(_ state: SegmentState<Value>, now: Date) -> SegmentState<Value> {
        let isStale = state.lastSuccessfulAt.map { now.timeIntervalSince($0) >= policy.staleInterval } ?? true
        return SegmentState(
            value: state.value,
            lastSuccessfulAt: state.lastSuccessfulAt,
            lastAttemptedAt: state.lastAttemptedAt,
            error: state.error,
            isStale: isStale
        )
    }

    func allMetadata() async -> [SyncMetadata] {
        var values: [SyncMetadata] = []
        for type in [RadarDatasetType.benchmark, .community, .sourceStatus] {
            if let metadata = try? await repository.metadata(sourceID: sourceID, datasetType: type) {
                values.append(metadata)
            }
        }
        return values
    }

}
