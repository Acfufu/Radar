import Foundation

extension RadarSyncCoordinator {
    func applyEnvelope(
        _ result: Result<RadarEnvelopeProjection, Error>,
        attemptedAt: Date
    ) async -> Bool {
        switch result {
        case .success(let envelope):
            let validators = await source.responseValidators().benchmark
            let benchmarkSaved = await saveBenchmark(envelope.benchmark, validators: validators, attemptedAt: attemptedAt)
            let statusSaved = source.supportsSourceStatusSegment
                ? await saveStatus(envelope.sourceStatus, validators: validators, attemptedAt: attemptedAt)
                : false
            return benchmarkSaved || statusSaved
        case .failure(let error):
            if let http = error as? RadarHTTPError, http.kind == .notModified {
                return await applyEnvelopeNotModified(attemptedAt: attemptedAt, validators: http.validators)
            }
            await recordFailure(
                source.supportsSourceStatusSegment ? [.benchmark, .sourceStatus] : [.benchmark],
                attemptedAt: attemptedAt,
                error: segmentError(error),
                retryAfter: retryDeadline(error, now: attemptedAt)
            )
            return false
        }
    }

    func applyCommunity(
        _ result: Result<CommunityDataset?, Error>,
        attemptedAt: Date
    ) async -> Bool {
        switch result {
        case .success(let dataset):
            guard let dataset else { return false }
            do {
                _ = try await repository.insertCommunity(dataset)
                let validators = await source.responseValidators().community
                try await repository.recordValidators(sourceID: sourceID, datasetType: .community, validators: validators)
                return true
            } catch {
                try? await repository.recordFailure(sourceID: sourceID, datasetType: .community, attemptedAt: attemptedAt, error: segmentError(error))
                return false
            }
        case .failure(let error):
            if let http = error as? RadarHTTPError, http.kind == .notModified {
                let state = try? await repository.communityState(sourceID: sourceID)
                guard state?.value != nil, state?.error == nil else {
                    try? await repository.recordValidators(sourceID: sourceID, datasetType: .community, validators: .empty)
                    try? await repository.recordFailure(
                        sourceID: sourceID,
                        datasetType: .community,
                        attemptedAt: attemptedAt,
                        error: SegmentError(kind: .decoding, message: "304 received without local community data")
                    )
                    return false
                }
                await recordNotModified([.community], attemptedAt: attemptedAt, validators: http.validators)
                return true
            }
            try? await repository.recordFailure(
                sourceID: sourceID,
                datasetType: .community,
                attemptedAt: attemptedAt,
                error: segmentError(error),
                retryAfter: retryDeadline(error, now: attemptedAt)
            )
            return false
        }
    }

    private func saveBenchmark(
        _ projection: SegmentProjection<BenchmarkDataset>,
        validators: HTTPValidators,
        attemptedAt: Date
    ) async -> Bool {
        guard let dataset = projection.value else {
            let error = projection.error ?? SegmentError(kind: .decoding, message: "Benchmark is unavailable")
            try? await repository.recordFailure(sourceID: sourceID, datasetType: .benchmark, attemptedAt: attemptedAt, error: error)
            return false
        }
        do {
            _ = try await repository.insertBenchmark(dataset)
            try await repository.recordValidators(sourceID: sourceID, datasetType: .benchmark, validators: validators)
            return true
        } catch {
            try? await repository.recordFailure(sourceID: sourceID, datasetType: .benchmark, attemptedAt: attemptedAt, error: segmentError(error))
            return false
        }
    }

    private func saveStatus(
        _ projection: SegmentProjection<SourceStatusDataset>,
        validators: HTTPValidators,
        attemptedAt: Date
    ) async -> Bool {
        guard let dataset = projection.value else {
            let error = projection.error ?? SegmentError(kind: .decoding, message: "Source status is unavailable")
            try? await repository.recordFailure(sourceID: sourceID, datasetType: .sourceStatus, attemptedAt: attemptedAt, error: error)
            return false
        }
        do {
            _ = try await repository.insertSourceStatus(dataset)
            try await repository.recordValidators(sourceID: sourceID, datasetType: .sourceStatus, validators: validators)
            return true
        } catch {
            try? await repository.recordFailure(sourceID: sourceID, datasetType: .sourceStatus, attemptedAt: attemptedAt, error: segmentError(error))
            return false
        }
    }

    private func recordNotModified(
        _ types: [RadarDatasetType],
        attemptedAt: Date,
        validators: HTTPValidators
    ) async {
        for type in types {
            try? await repository.recordNotModified(sourceID: sourceID, datasetType: type, attemptedAt: attemptedAt, etag: validators.etag, lastModified: validators.lastModified)
        }
    }

    private func applyEnvelopeNotModified(
        attemptedAt: Date,
        validators: HTTPValidators
    ) async -> Bool {
        let benchmark = try? await repository.benchmarkState(sourceID: sourceID)
        let status = try? await repository.sourceStatusState(sourceID: sourceID)
        var success = false
        if benchmark?.value != nil, benchmark?.error == nil {
            await recordNotModified([.benchmark], attemptedAt: attemptedAt, validators: validators)
            success = true
        } else {
            await rejectOrphanNotModified(.benchmark, attemptedAt: attemptedAt)
        }
        if !source.supportsSourceStatusSegment {
            return success
        }
        if status?.value != nil, status?.error == nil {
            await recordNotModified([.sourceStatus], attemptedAt: attemptedAt, validators: validators)
            success = true
        } else {
            await rejectOrphanNotModified(.sourceStatus, attemptedAt: attemptedAt)
        }
        return success
    }

    private func rejectOrphanNotModified(_ type: RadarDatasetType, attemptedAt: Date) async {
        try? await repository.recordValidators(sourceID: sourceID, datasetType: type, validators: .empty)
        try? await repository.recordFailure(
            sourceID: sourceID,
            datasetType: type,
            attemptedAt: attemptedAt,
            error: SegmentError(kind: .decoding, message: "304 received without local last-known-good data")
        )
    }

    private func recordFailure(
        _ types: [RadarDatasetType],
        attemptedAt: Date,
        error: SegmentError,
        retryAfter: Date?
    ) async {
        for type in types {
            try? await repository.recordFailure(sourceID: sourceID, datasetType: type, attemptedAt: attemptedAt, error: error, retryAfter: retryAfter)
        }
    }

    private func segmentError(_ error: Error) -> SegmentError {
        if let error = error as? SegmentError { return error }
        if let error = error as? RadarHTTPError {
            return SegmentError(kind: error.kind == .network ? .network : .http, message: "\(source.descriptor.displayName) HTTP acquisition failed")
        }
        return SegmentError(kind: .decoding, message: "\(source.descriptor.displayName) synchronization failed")
    }

    private func retryDeadline(_ error: Error, now: Date) -> Date? {
        guard let retry = (error as? RadarHTTPError)?.retryAfter else { return nil }
        let deadline: Date = switch retry {
        case .seconds(let seconds): now.addingTimeInterval(TimeInterval(seconds))
        case .date(let date): date
        }
        return min(deadline, now.addingTimeInterval(policy.maximumBackoff))
    }
}
