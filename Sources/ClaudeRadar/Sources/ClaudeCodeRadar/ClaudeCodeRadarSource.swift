import Foundation

actor ClaudeCodeRadarSource: RadarSource {
    nonisolated let descriptor: RadarSourceDescriptor

    private let configuration: ClaudeRadarConfiguration
    private let transport: any HTTPTransport
    private let rawSampleStore: RawSampleStore?
    private let parser = ClaudeRadarParser()
    private var validators = HTTPValidators.empty
    private var latestValidators = HTTPValidators.empty
    private var communityValidators = HTTPValidators.empty
    private var latestCommunityValidators = HTTPValidators.empty
    private var cachedAcquisition: BenchmarkAcquisition?
    private var acquisitionIsRunning = false
    private var acquisitionGeneration = 0
    private var acquisitionWaiters: [CheckedContinuation<AcquisitionOutcome, Never>] = []
    private var rawPersistenceTasks: [Int: Task<Void, Never>] = [:]
    private var nextRawPersistenceID = 0

    init(
        configuration: ClaudeRadarConfiguration = .production,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        rawSampleStore: RawSampleStore? = nil
    ) {
        self.configuration = configuration
        self.transport = transport
        self.rawSampleStore = rawSampleStore
        descriptor = ClaudeRadarConfiguration.descriptor
    }

    func beginAcquisition(
        validators: HTTPValidators,
        communityValidators: HTTPValidators = .empty
    ) {
        self.validators = validators
        self.communityValidators = communityValidators
        acquisitionGeneration += 1
        cachedAcquisition = nil
        acquisitionIsRunning = false
        resumeWaiters(.failure(CancellationError()))
    }

    func acquireBenchmarkEnvelope() async throws -> ClaudeRadarEnvelopeProjection {
        if let cachedAcquisition {
            return cachedAcquisition.projection
        }
        if acquisitionIsRunning {
            return try await withCheckedContinuation { acquisitionWaiters.append($0) }.value.projection
        }
        acquisitionIsRunning = true
        let generation = acquisitionGeneration
        let request = Self.request(url: configuration.benchmarkURL, validators: validators)
        do {
            let payload: HTTPTransportResponse
            do {
                payload = try await transport.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw RadarHTTPError(kind: .network)
            }
            try ensureCurrent(generation)
            let fetchedAt = Date()
            let validators: HTTPValidators
            do {
                validators = try Self.validate(payload)
            } catch let error as RadarHTTPError where error.kind == .notModified {
                throw error
            } catch {
                try ensureCurrent(generation)
                await saveRaw(payload.data, outcome: .httpFailed, at: fetchedAt, generation: generation)
                throw error
            }
            let projection: ClaudeRadarEnvelopeProjection
            do {
                projection = try parser.parseBenchmarkEnvelope(payload.data, fetchedAt: fetchedAt)
            } catch {
                try ensureCurrent(generation)
                await saveRaw(payload.data, outcome: .decodingFailed, at: fetchedAt, generation: generation)
                throw error
            }
            let errors = [projection.benchmark.error, projection.sourceStatus.error].compactMap { $0 }
            let outcome: RawSampleOutcome = if errors.isEmpty {
                .success
            } else if errors.contains(where: { $0.kind == .validation }) {
                .validationFailed
            } else {
                .decodingFailed
            }
            try ensureCurrent(generation)
            await saveRaw(payload.data, outcome: outcome, at: fetchedAt, generation: generation)
            let acquisition = BenchmarkAcquisition(
                projection: projection,
                validators: validators
            )
            guard generation == acquisitionGeneration else { throw CancellationError() }
            cachedAcquisition = acquisition
            acquisitionIsRunning = false
            latestValidators = acquisition.validators
            resumeWaiters(.success(acquisition))
            return acquisition.projection
        } catch {
            if generation == acquisitionGeneration {
                acquisitionIsRunning = false
                resumeWaiters(.failure(error))
            }
            throw error
        }
    }

    func fetchBenchmark() async throws -> BenchmarkDataset {
        let projection = try await acquireBenchmarkEnvelope().benchmark
        if let value = projection.value { return value }
        throw projection.error ?? SegmentError(kind: .decoding, message: "Benchmark is unavailable")
    }

    func fetchSourceStatus() async throws -> SourceStatusDataset? {
        let projection = try await acquireBenchmarkEnvelope().sourceStatus
        if let value = projection.value { return value }
        throw projection.error ?? SegmentError(kind: .decoding, message: "Source status is unavailable")
    }

    func fetchCommunity() async throws -> CommunityDataset? {
        guard let url = configuration.communityURL else { return nil }
        let generation = acquisitionGeneration
        let payload: HTTPTransportResponse
        do {
            payload = try await transport.data(for: Self.request(url: url, validators: communityValidators))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RadarHTTPError(kind: .network)
        }
        try ensureCurrent(generation)
        let fetchedAt = Date()
        do {
            latestCommunityValidators = try Self.validate(payload)
        } catch let error as RadarHTTPError where error.kind == .notModified {
            throw error
        } catch {
            try ensureCurrent(generation)
            await saveRaw(payload.data, outcome: .httpFailed, at: fetchedAt, generation: generation)
            throw error
        }
        let projection: SegmentProjection<CommunityDataset>
        do {
            projection = try parser.parseCommunityEnvelope(payload.data, fetchedAt: fetchedAt)
        } catch {
            try ensureCurrent(generation)
            await saveRaw(payload.data, outcome: .decodingFailed, at: fetchedAt, generation: generation)
            throw error
        }
        let outcome: RawSampleOutcome = switch projection.error?.kind {
        case nil: .success
        case .validation: .validationFailed
        default: .decodingFailed
        }
        try ensureCurrent(generation)
        await saveRaw(payload.data, outcome: outcome, at: fetchedAt, generation: generation)
        try ensureCurrent(generation)
        if let value = projection.value { return value }
        throw projection.error ?? SegmentError(kind: .decoding, message: "Community is unavailable")
    }

    func responseValidators() -> (benchmark: HTTPValidators, community: HTTPValidators) {
        (latestValidators, latestCommunityValidators)
    }

    func hasCommunityEndpoint() -> Bool {
        configuration.communityURL != nil
    }

    func cancelAll() async {
        acquisitionGeneration += 1
        cachedAcquisition = nil
        acquisitionIsRunning = false
        resumeWaiters(.failure(CancellationError()))
        await transport.cancelAll()
        let registeredPersistence = Array(rawPersistenceTasks.values)
        for task in registeredPersistence { await task.value }
        await rawSampleStore?.flush()
    }

    private func resumeWaiters(_ outcome: AcquisitionOutcome) {
        let waiters = acquisitionWaiters
        acquisitionWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: outcome) }
    }

    private func saveRaw(
        _ data: Data,
        outcome: RawSampleOutcome,
        at date: Date,
        generation: Int
    ) async {
        guard generation == acquisitionGeneration, let rawSampleStore else { return }
        nextRawPersistenceID += 1
        let persistenceID = nextRawPersistenceID
        let task = Task {
            _ = try? await rawSampleStore.save(data, sourceID: .claudeCodeRadar, outcome: outcome, at: date)
        }
        rawPersistenceTasks[persistenceID] = task
        await task.value
        rawPersistenceTasks[persistenceID] = nil
    }

    private func ensureCurrent(_ generation: Int) throws {
        guard generation == acquisitionGeneration, !Task.isCancelled else { throw CancellationError() }
    }

}

private struct BenchmarkAcquisition: Sendable {
    let projection: ClaudeRadarEnvelopeProjection
    let validators: HTTPValidators
}

private enum AcquisitionOutcome: @unchecked Sendable {
    case success(BenchmarkAcquisition)
    case failure(Error)

    var value: BenchmarkAcquisition {
        get throws {
            switch self {
            case .success(let acquisition): acquisition
            case .failure(let error): throw error
            }
        }
    }
}
