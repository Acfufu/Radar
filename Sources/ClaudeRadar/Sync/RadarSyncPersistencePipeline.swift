import Foundation

extension RadarSyncCoordinator {
    func performSync(generation: Int, eligibility: SyncEndpointEligibility) async {
        let attemptedAt = clock.now()
        let persistedFailureCount = await allMetadata().compactMap(\.consecutiveFailures).max() ?? 0
        failureCount = max(failureCount, persistedFailureCount)
        let benchmarkMetadata = try? await repository.metadata(sourceID: sourceID, datasetType: .benchmark)
        let communityMetadata = try? await repository.metadata(sourceID: sourceID, datasetType: .community)
        let benchmarkState = try? await repository.benchmarkState(sourceID: sourceID)
        let statusState = try? await repository.sourceStatusState(sourceID: sourceID)
        let communityState = try? await repository.communityState(sourceID: sourceID)
        let sharedCacheIsClean = benchmarkState?.value != nil && benchmarkState?.error == nil
            && (!source.supportsSourceStatusSegment || (statusState?.value != nil && statusState?.error == nil))
        let communityCacheIsClean = communityState?.value != nil && communityState?.error == nil
        guard lifecycleAllowsWork(generation) else { return }
        await source.beginAcquisition(
            validators: sharedCacheIsClean
                ? HTTPValidators(etag: benchmarkMetadata?.etag, lastModified: benchmarkMetadata?.lastModified)
                : .empty,
            communityValidators: communityCacheIsClean
                ? HTTPValidators(etag: communityMetadata?.etag, lastModified: communityMetadata?.lastModified)
                : .empty
        )
        guard lifecycleAllowsWork(generation) else { return }
        async let envelope = captureEnvelope(if: eligibility.shared)
        async let community = captureCommunity(if: eligibility.community)
        let results = await (envelope, community)
        guard !Task.isCancelled, lifecycleAllowsWork(generation) else { return }
        guard let persistence = registerPersistence(results, attemptedAt: attemptedAt, generation: generation) else { return }
        await persistence.value
    }

    private func registerPersistence(
        _ results: (Result<RadarEnvelopeProjection, Error>?, Result<CommunityDataset?, Error>?),
        attemptedAt: Date,
        generation: Int
    ) -> Task<Void, Never>? {
        guard lifecycleAllowsWork(generation) else { return nil }
        nextPersistenceID += 1
        let persistenceID = nextPersistenceID
        let task = Task {
            await self.persist(results, attemptedAt: attemptedAt, generation: generation)
            self.finishPersistence(persistenceID)
        }
        persistenceTasks[persistenceID] = task
        return task
    }

    private func persist(
        _ results: (Result<RadarEnvelopeProjection, Error>?, Result<CommunityDataset?, Error>?),
        attemptedAt: Date,
        generation: Int
    ) async {
        await persistenceCheckpoint?()
        guard lifecycleAllowsWork(generation) else { return }
        if let envelope = results.0 {
            guard lifecycleAllowsWork(generation) else { return }
            _ = await applyEnvelope(envelope, attemptedAt: attemptedAt)
        }
        if let community = results.1 {
            guard lifecycleAllowsWork(generation) else { return }
            _ = await applyCommunity(community, attemptedAt: attemptedAt)
        }
        var attemptedTypes: Set<RadarDatasetType> = []
        if results.0 != nil {
            attemptedTypes.insert(.benchmark)
            if source.supportsSourceStatusSegment { attemptedTypes.insert(.sourceStatus) }
        }
        if results.1 != nil { attemptedTypes.insert(.community) }
        guard lifecycleAllowsWork(generation) else { return }
        await refreshSegmentBackoff(
            attemptedAt: attemptedAt,
            attemptedTypes: attemptedTypes,
            generation: generation
        )
        guard lifecycleAllowsWork(generation) else { return }
        if let projectionDidChange, let current = try? await projection() {
            guard lifecycleAllowsWork(generation) else { return }
            await projectionDidChange(current)
        }
    }

    private func finishPersistence(_ persistenceID: Int) {
        persistenceTasks[persistenceID] = nil
    }

    private func captureEnvelope(if eligible: Bool) async -> Result<RadarEnvelopeProjection, Error>? {
        guard eligible else { return nil }
        do { return .success(try await source.acquireBenchmarkEnvelope()) }
        catch { return .failure(error) }
    }

    private func captureCommunity(if eligible: Bool) async -> Result<CommunityDataset?, Error>? {
        guard eligible else { return nil }
        do { return .success(try await source.fetchCommunity()) }
        catch { return .failure(error) }
    }

    private func refreshSegmentBackoff(
        attemptedAt: Date,
        attemptedTypes: Set<RadarDatasetType>,
        generation: Int
    ) async {
        var maximumFailureCount = 0
        var maximumDeadline: Date?
        for type in [RadarDatasetType.benchmark, .community, .sourceStatus] {
            guard let metadata = try? await repository.metadata(sourceID: sourceID, datasetType: type) else { continue }
            guard lifecycleAllowsWork(generation) else { return }
            let count = metadata.lastError == nil ? 0 : max(metadata.consecutiveFailures ?? 0, 1)
            let deadline = count == 0 ? nil : attemptedAt.addingTimeInterval(policy.backoff(failureCount: count))
            if attemptedTypes.contains(type) {
                try? await repository.recordBackoff(
                    sourceID: sourceID,
                    datasetType: type,
                    until: deadline,
                    failureCount: count
                )
            }
            maximumFailureCount = max(maximumFailureCount, count)
            if let deadline { maximumDeadline = max(maximumDeadline ?? deadline, deadline) }
        }
        guard lifecycleAllowsWork(generation) else { return }
        failureCount = maximumFailureCount
        backoffDeadline = maximumDeadline
    }
}
